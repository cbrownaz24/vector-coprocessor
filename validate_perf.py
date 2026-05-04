#!/usr/bin/env python3
"""
Performance validation script: vector coprocessor vs scalar baseline.

Runs all ISA tests, paired scalar/vector benchmarks, and ubmark baselines,
then reports cycles, IPC, speedup, convoy/chime analysis, and generates
summary charts saved to perf_results/.
"""

import subprocess
import re
import sys
import os
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.gridspec import GridSpec

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

REPO = Path(__file__).parent.resolve()
BUILD_DIR = REPO / "build"
SIM = BUILD_DIR / "riscvvec-sim"
TESTS_VMH = REPO / "tests" / "build" / "vmh"
UBMARK_VMH = REPO / "ubmark" / "build" / "vmh"
OUT_DIR = REPO / "perf_results"
OUT_DIR.mkdir(exist_ok=True)

# ---------------------------------------------------------------------------
# Static benchmark definitions
# ---------------------------------------------------------------------------
# Each paired benchmark describes the vector instruction sequence between
# stats_on / stats_off markers so we can compute theoretical chime cycles.
#
# Convoy = a group of vector instructions with no RAW dependency that could
# issue together.  Because this design has a single vector functional unit
# (one command processed at a time by VecCtrl), every vector instruction
# occupies its own convoy – there is no chaining.
#
# Chime  = time to execute one convoy = VL element cycles.

PAIRED_BMARKS = [
    {
        "name":       "vvadd",
        "label":      "VVADD (32 elem)",
        "vl":         32,
        "scalar_vmh": TESTS_VMH / "riscv-bmark-vvadd-scalar.vmh",
        "vector_vmh": TESTS_VMH / "riscv-bmark-vvadd-vector.vmh",
        # Instructions measured inside stats region, in issue order.
        # Each entry: (label, type, depends_on_convoy_ids)
        # "type" is "mem" or "arith"; depends_on lists convoy ids that must
        # complete before this one can start (RAW hazards → new convoy).
        "vec_ops": [
            ("VLW v0,src0",  "mem",   []),
            ("VLW v1,src1",  "mem",   []),
            ("VVADD v2,v0,v1","arith", [1, 2]),
            ("VSW v2,dest",  "mem",   [3]),
        ],
    },
    {
        "name":       "daxpy",
        "label":      "DAXPY (32 elem)",
        "vl":         32,
        "scalar_vmh": TESTS_VMH / "riscv-bmark-daxpy-scalar.vmh",
        "vector_vmh": TESTS_VMH / "riscv-bmark-daxpy-vector.vmh",
        "vec_ops": [
            ("VLW v0,x",     "mem",   []),
            ("VLW v1,y",     "mem",   []),
            ("VSMUL v2,v0,a","arith", [1]),
            ("VVADD v3,v2,v1","arith",[3, 2]),
            ("VSW v3,y",     "mem",   [4]),
        ],
    },
    {
        "name":       "saxpy",
        "label":      "SAXPY (16 elem)",
        "vl":         16,
        "scalar_vmh": TESTS_VMH / "riscv-bmark-saxpy-scalar.vmh",
        "vector_vmh": TESTS_VMH / "riscv-bmark-saxpy-vector.vmh",
        "vec_ops": [
            ("VLW v0,src",   "mem",   []),
            ("VSMUL v1,v0,5","arith", [1]),
            ("VSW v1,dest",  "mem",   [2]),
        ],
    },
]

UBMARKS = [
    {"name": "ubmark-vvadd",        "label": "vvadd (100 elem)", "vmh": UBMARK_VMH / "ubmark-vvadd.vmh"},
    {"name": "ubmark-bin-search",   "label": "bin-search",       "vmh": UBMARK_VMH / "ubmark-bin-search.vmh"},
    {"name": "ubmark-cmplx-mult",   "label": "cmplx-mult",       "vmh": UBMARK_VMH / "ubmark-cmplx-mult.vmh"},
    {"name": "ubmark-masked-filter","label": "masked-filter",    "vmh": UBMARK_VMH / "ubmark-masked-filter.vmh"},
]

# All 44 ISA tests
ISA_TESTS = [f"riscv-{t}.vmh" for t in (
    "add addi and andi beq bge bgeu blt bltu bne div divu j jal jalr jr "
    "lb lbu lh lhu lui lw mul or ori rem remu sb sh sll slli slt slti "
    "sltiu sltu sra srai srl srli sub sw xor xori vec"
).split()]

# ---------------------------------------------------------------------------
# Simulation runner
# ---------------------------------------------------------------------------

def run_sim(vmh: Path, max_cycles: int = 200000) -> dict:
    """Run simulator, parse stdout/stderr, return stats dict."""
    cmd = [str(SIM), "+stats=1", f"+exe={vmh}", f"+max-cycles={max_cycles}"]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(BUILD_DIR))
    out = result.stdout + result.stderr

    stats: dict = {"vmh": vmh.name, "raw": out}
    stats["passed"] = "*** PASSED ***" in out
    stats["failed_msg"] = ""
    if "*** FAILED ***" in out:
        m = re.search(r"\*{3} FAILED \*{3}(.*)", out)
        stats["failed_msg"] = m.group(1).strip() if m else "unknown"

    for key, pattern in [
        ("num_cycles", r"num_cycles\s*=\s*(\d+)"),
        ("num_inst",   r"num_inst\s*=\s*(\d+)"),
    ]:
        m = re.search(pattern, out)
        stats[key] = int(m.group(1)) if m else None

    m = re.search(r"ipc\s*=\s*([0-9.]+)", out)
    stats["ipc"] = float(m.group(1)) if m else None

    return stats

# ---------------------------------------------------------------------------
# Convoy / chime analysis
# ---------------------------------------------------------------------------

def convoy_analysis(bmark: dict) -> dict:
    """
    Compute convoy and chime metrics for a paired benchmark.

    Single-issue vector unit ⟹ each instruction is its own convoy.
    Chime = VL element cycles.

    Returns a dict with:
      - convoys     : list of convoy descriptions
      - num_convoys : total convoy count
      - num_chimes  : same (one chime per convoy in this design)
      - theoretical_vec_cycles : num_convoys × VL
    """
    vl = bmark["vl"]
    ops = bmark["vec_ops"]

    convoys = []
    for idx, (label, op_type, _deps) in enumerate(ops):
        convoy_id = idx + 1
        convoys.append({
            "id":       convoy_id,
            "inst":     label,
            "type":     op_type,
            "chimes":   1,
            "el_cycles": vl,
        })

    return {
        "convoys":                convoys,
        "num_convoys":            len(convoys),
        "num_chimes":             len(convoys),   # 1 chime per convoy
        "theoretical_vec_cycles": len(convoys) * vl,
        "vl":                     vl,
    }

# ---------------------------------------------------------------------------
# Text report helpers
# ---------------------------------------------------------------------------

def fmt_row(cols, widths):
    return "  ".join(str(c).ljust(w) for c, w in zip(cols, widths))

def section(title):
    print()
    print("=" * 72)
    print(f"  {title}")
    print("=" * 72)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if not SIM.exists():
        print(f"ERROR: simulator not found at {SIM}")
        print("Run 'make' inside build/ first.")
        sys.exit(1)

    print()
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║        Vector Coprocessor Performance Validation                 ║")
    print("╚══════════════════════════════════════════════════════════════════╝")

    # -----------------------------------------------------------------------
    # 1. ISA test suite
    # -----------------------------------------------------------------------
    section("ISA Test Suite (correctness)")

    isa_results = []
    passed = failed = 0
    for test in ISA_TESTS:
        vmh = TESTS_VMH / test
        if not vmh.exists():
            print(f"  SKIP  {test}  (vmh not found)")
            continue
        s = run_sim(vmh)
        ok = s["passed"]
        passed += ok
        failed += (not ok)
        status = "PASS" if ok else f"FAIL ({s['failed_msg']})"
        cyc = s["num_cycles"] if s["num_cycles"] is not None else "—"
        print(f"  [{status:<30}]  cycles={str(cyc):<6}  {test}")
        isa_results.append(s)

    print()
    print(f"  Result: {passed}/{passed+failed} passed", end="")
    if failed:
        print(f"  *** {failed} FAILED ***")
    else:
        print("  ✓ ALL PASSED")

    # -----------------------------------------------------------------------
    # 2. Paired scalar vs vector benchmarks
    # -----------------------------------------------------------------------
    section("Scalar vs Vector Benchmarks")

    paired_data = []
    hdr = ["Benchmark", "Impl", "Cycles", "Insts", "IPC", "Speedup"]
    wid = [22, 8, 8, 7, 8, 8]
    print("  " + fmt_row(hdr, wid))
    print("  " + "-" * 70)

    for bm in PAIRED_BMARKS:
        s_s = run_sim(bm["scalar_vmh"])
        s_v = run_sim(bm["vector_vmh"])

        speedup = (s_s["num_cycles"] / s_v["num_cycles"]
                   if s_s["num_cycles"] and s_v["num_cycles"] else None)

        def row(impl, s, sp=""):
            cyc  = s["num_cycles"] if s["num_cycles"] is not None else "err"
            inst = s["num_inst"]   if s["num_inst"]   is not None else "err"
            ipc  = f"{s['ipc']:.3f}" if s["ipc"] is not None else "err"
            ok   = "✓" if s["passed"] else "✗"
            sp_s = f"{sp:.2f}x" if sp != "" else "—"
            print("  " + fmt_row([f"{ok} {bm['label']}", impl, cyc, inst, ipc, sp_s], wid))

        row("scalar", s_s)
        row("vector", s_v, speedup)
        print()

        ca = convoy_analysis(bm)
        paired_data.append({
            "bmark":   bm,
            "scalar":  s_s,
            "vector":  s_v,
            "speedup": speedup,
            "convoy":  ca,
        })

    # -----------------------------------------------------------------------
    # 3. Convoy / chime analysis
    # -----------------------------------------------------------------------
    section("Convoy & Chime Analysis")

    for d in paired_data:
        bm = d["bmark"]
        ca = d["convoy"]
        vs = d["vector"]
        ss = d["scalar"]

        print(f"\n  {bm['label']}  (VL={ca['vl']})")
        print(f"  {'─'*50}")
        print(f"  Convoys  : {ca['num_convoys']}   (one per vector instruction — single FU)")
        print(f"  Chimes   : {ca['num_chimes']}   (1 chime = {ca['vl']} element cycles)")
        print(f"  Theoretical vector-unit cycles : {ca['theoretical_vec_cycles']}")
        print(f"  Actual total cycles (vector)   : {vs['num_cycles']}")
        overhead = vs["num_cycles"] - ca["theoretical_vec_cycles"]
        print(f"  Scalar/setup overhead          : {overhead} cycles  "
              f"({100*overhead/vs['num_cycles']:.1f}% of total)")
        print(f"  Scalar baseline cycles         : {ss['num_cycles']}")
        if d["speedup"]:
            print(f"  Speedup                        : {d['speedup']:.2f}x")

        print()
        print(f"  {'Id':<4} {'Instruction':<22} {'Type':<6} {'Chimes':<8} {'El-cycles'}")
        print(f"  {'─'*56}")
        for c in ca["convoys"]:
            print(f"  {c['id']:<4} {c['inst']:<22} {c['type']:<6} {c['chimes']:<8} {c['el_cycles']}")

    # -----------------------------------------------------------------------
    # 4. Ubmark baselines (scalar C programs)
    # -----------------------------------------------------------------------
    section("Ubmark Baselines (scalar C, regression check)")

    ub_data = []
    hdr2 = ["Benchmark", "Status", "Cycles", "Insts", "IPC"]
    wid2 = [26, 8, 8, 7, 8]
    print("  " + fmt_row(hdr2, wid2))
    print("  " + "-" * 60)
    for ub in UBMARKS:
        s = run_sim(ub["vmh"])
        ok = "✓ PASS" if s["passed"] else "✗ FAIL"
        cyc  = s["num_cycles"] if s["num_cycles"] is not None else "err"
        inst = s["num_inst"]   if s["num_inst"]   is not None else "err"
        ipc  = f"{s['ipc']:.3f}" if s["ipc"] is not None else "err"
        print("  " + fmt_row([ub["label"], ok, cyc, inst, ipc], wid2))
        ub_data.append({"ub": ub, "stats": s})

    # -----------------------------------------------------------------------
    # 5. Summary table
    # -----------------------------------------------------------------------
    section("Performance Summary")
    print()
    print(f"  {'Benchmark':<26} {'Scalar cyc':>10} {'Vector cyc':>10} {'Speedup':>8}")
    print(f"  {'─'*58}")
    for d in paired_data:
        sc = d["scalar"]["num_cycles"] or 0
        vc = d["vector"]["num_cycles"] or 0
        sp = f"{d['speedup']:.2f}x" if d["speedup"] else "—"
        print(f"  {d['bmark']['label']:<26} {sc:>10} {vc:>10} {sp:>8}")

    # -----------------------------------------------------------------------
    # 6. Generate plots
    # -----------------------------------------------------------------------
    _make_plots(paired_data, ub_data)

    print()
    print(f"Charts saved to  {OUT_DIR}/")
    print()

# ---------------------------------------------------------------------------
# Plot generation
# ---------------------------------------------------------------------------

SCALAR_COLOR = "#4878CF"
VECTOR_COLOR = "#E87722"
OVERHEAD_COLOR = "#AAAAAA"
MEM_COLOR     = "#5BAD72"
ARITH_COLOR   = "#CF6678"

def _make_plots(paired_data, ub_data):
    # ---- Figure 1: cycles & speedup bar charts ----------------------------
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    fig.suptitle("Vector Coprocessor vs Scalar Baseline", fontsize=14, fontweight="bold")

    labels  = [d["bmark"]["label"] for d in paired_data]
    s_cycs  = [d["scalar"]["num_cycles"] or 0 for d in paired_data]
    v_cycs  = [d["vector"]["num_cycles"] or 0 for d in paired_data]
    speedups = [d["speedup"] or 0 for d in paired_data]

    x = np.arange(len(labels))
    w = 0.35

    ax = axes[0]
    bars_s = ax.bar(x - w/2, s_cycs, w, label="Scalar", color=SCALAR_COLOR)
    bars_v = ax.bar(x + w/2, v_cycs, w, label="Vector", color=VECTOR_COLOR)
    ax.set_xlabel("Benchmark")
    ax.set_ylabel("Simulation Cycles")
    ax.set_title("Cycles: Scalar vs Vector")
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=12, ha="right")
    ax.legend()
    ax.grid(axis="y", alpha=0.3)
    for bar in bars_s:
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 10,
                str(int(bar.get_height())), ha="center", va="bottom", fontsize=8)
    for bar in bars_v:
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 10,
                str(int(bar.get_height())), ha="center", va="bottom", fontsize=8)

    ax2 = axes[1]
    bars_sp = ax2.bar(x, speedups, color=VECTOR_COLOR, alpha=0.85)
    ax2.axhline(1.0, color="black", linewidth=1, linestyle="--", alpha=0.5, label="baseline (1x)")
    ax2.set_xlabel("Benchmark")
    ax2.set_ylabel("Speedup (scalar / vector cycles)")
    ax2.set_title("Speedup from Vectorization")
    ax2.set_xticks(x)
    ax2.set_xticklabels(labels, rotation=12, ha="right")
    ax2.legend()
    ax2.grid(axis="y", alpha=0.3)
    for bar, sp in zip(bars_sp, speedups):
        ax2.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.05,
                 f"{sp:.2f}x", ha="center", va="bottom", fontsize=9, fontweight="bold")

    fig.tight_layout()
    fig.savefig(OUT_DIR / "01_cycles_speedup.png", dpi=150)
    plt.close(fig)

    # ---- Figure 2: IPC comparison ----------------------------------------
    fig, ax = plt.subplots(figsize=(8, 5))
    fig.suptitle("IPC: Scalar vs Vector", fontsize=13, fontweight="bold")

    s_ipc = [d["scalar"]["ipc"] or 0 for d in paired_data]
    v_ipc = [d["vector"]["ipc"] or 0 for d in paired_data]

    ax.bar(x - w/2, s_ipc, w, label="Scalar IPC", color=SCALAR_COLOR)
    ax.bar(x + w/2, v_ipc, w, label="Vector IPC*", color=VECTOR_COLOR)
    ax.set_xlabel("Benchmark")
    ax.set_ylabel("IPC (scalar instructions / cycle)")
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=12, ha="right")
    ax.legend()
    ax.grid(axis="y", alpha=0.3)
    note = ("* Vector IPC counts scalar dispatch instructions only.\n"
            "  Each dispatch instruction represents up to VL element-ops.")
    ax.text(0.01, 0.97, note, transform=ax.transAxes, fontsize=7,
            va="top", ha="left", style="italic", color="gray")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "02_ipc_comparison.png", dpi=150)
    plt.close(fig)

    # ---- Figure 3: convoy / chime breakdown per benchmark -----------------
    n = len(paired_data)
    fig, axes = plt.subplots(1, n, figsize=(5 * n, 5))
    if n == 1:
        axes = [axes]
    fig.suptitle("Convoy & Chime Breakdown (Vector Benchmarks)", fontsize=13, fontweight="bold")

    for ax, d in zip(axes, paired_data):
        bm  = d["bmark"]
        ca  = d["convoy"]
        v_cyc = d["vector"]["num_cycles"] or 0
        theo  = ca["theoretical_vec_cycles"]
        over  = v_cyc - theo

        convoy_labels = [c["inst"].split(",")[0] for c in ca["convoys"]]
        convoy_els    = [c["el_cycles"] for c in ca["convoys"]]
        colors        = [MEM_COLOR if c["type"] == "mem" else ARITH_COLOR
                         for c in ca["convoys"]]

        # Stacked: theoretical chime cycles | overhead
        bar_y = np.arange(len(convoy_labels))
        ax.barh(bar_y, convoy_els, color=colors, alpha=0.85, height=0.6)
        for i, (lbl, el) in enumerate(zip(convoy_labels, convoy_els)):
            ax.text(el + 0.5, i, f"{el} cy", va="center", fontsize=8)

        ax.set_xlabel("Element cycles per chime (= VL)")
        ax.set_title(f"{bm['label']}\n"
                     f"{ca['num_convoys']} convoys / {ca['num_chimes']} chimes\n"
                     f"theory={theo} cy  actual={v_cyc} cy  overhead={over} cy")
        ax.set_yticks(bar_y)
        ax.set_yticklabels(convoy_labels)
        ax.grid(axis="x", alpha=0.3)

        mem_patch   = mpatches.Patch(color=MEM_COLOR,   label="memory op")
        arith_patch = mpatches.Patch(color=ARITH_COLOR, label="arith op")
        ax.legend(handles=[mem_patch, arith_patch], fontsize=8, loc="lower right")

    fig.tight_layout()
    fig.savefig(OUT_DIR / "03_convoy_chime.png", dpi=150)
    plt.close(fig)

    # ---- Figure 4: cycle budget (stacked: chime cycles + overhead) --------
    fig, ax = plt.subplots(figsize=(8, 5))
    fig.suptitle("Vector Benchmark Cycle Budget", fontsize=13, fontweight="bold")

    theos    = [d["convoy"]["theoretical_vec_cycles"] for d in paired_data]
    overheads = [max(0, (d["vector"]["num_cycles"] or 0) - t)
                 for d, t in zip(paired_data, theos)]

    ax.bar(x, theos,    color=VECTOR_COLOR, label="Chime cycles (VL × convoys)")
    ax.bar(x, overheads, bottom=theos, color=OVERHEAD_COLOR, label="Scalar setup / VFENCE overhead")
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=12, ha="right")
    ax.set_ylabel("Cycles")
    ax.set_title("Where Vector Cycles Are Spent")
    ax.legend()
    ax.grid(axis="y", alpha=0.3)

    for i, (th, oh) in enumerate(zip(theos, overheads)):
        total = th + oh
        pct   = 100 * th / total if total else 0
        ax.text(i, total + 5, f"{pct:.0f}% compute", ha="center", fontsize=8)

    fig.tight_layout()
    fig.savefig(OUT_DIR / "04_cycle_budget.png", dpi=150)
    plt.close(fig)

    # ---- Figure 5: ubmark scalar baseline ----------------------------------
    ub_labels = [d["ub"]["label"] for d in ub_data]
    ub_cycs   = [d["stats"]["num_cycles"] or 0 for d in ub_data]
    ub_ipc    = [d["stats"]["ipc"]        or 0 for d in ub_data]
    ub_pass   = [d["stats"]["passed"]         for d in ub_data]

    fig, (ax_c, ax_i) = plt.subplots(1, 2, figsize=(12, 5))
    fig.suptitle("Ubmark Scalar Baselines", fontsize=13, fontweight="bold")

    bar_colors = [SCALAR_COLOR if ok else "red" for ok in ub_pass]
    xi = np.arange(len(ub_labels))

    ax_c.bar(xi, ub_cycs, color=bar_colors)
    ax_c.set_xticks(xi)
    ax_c.set_xticklabels(ub_labels, rotation=15, ha="right")
    ax_c.set_ylabel("Simulation Cycles")
    ax_c.set_title("Cycle Counts")
    ax_c.grid(axis="y", alpha=0.3)
    for i, cyc in enumerate(ub_cycs):
        ax_c.text(i, cyc + 30, str(cyc), ha="center", fontsize=8)

    ax_i.bar(xi, ub_ipc, color=bar_colors)
    ax_i.set_xticks(xi)
    ax_i.set_xticklabels(ub_labels, rotation=15, ha="right")
    ax_i.set_ylabel("IPC")
    ax_i.set_title("Instructions Per Cycle")
    ax_i.grid(axis="y", alpha=0.3)
    for i, ipc in enumerate(ub_ipc):
        ax_i.text(i, ipc + 0.01, f"{ipc:.2f}", ha="center", fontsize=8)

    pass_patch = mpatches.Patch(color=SCALAR_COLOR, label="PASS")
    fail_patch = mpatches.Patch(color="red",         label="FAIL")
    ax_c.legend(handles=[pass_patch, fail_patch])

    fig.tight_layout()
    fig.savefig(OUT_DIR / "05_ubmark_baseline.png", dpi=150)
    plt.close(fig)


if __name__ == "__main__":
    main()
