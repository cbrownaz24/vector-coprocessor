#!/usr/bin/env python3
"""
make_plots.py - spits out the eval figure suite.

all figs use real measured data. each fig hits 1 question and uses
scale-isolated axes when data spans varies. run AFTER run_bench.py and
sweep_bench.py have populated results/.
"""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

import plot_lib as L
from energy_model import (
    estimate_energy, lookup_profile,
)

# compact labels for procs (used on x-axes when space tight)
SHORT_LABEL = {
    "riscvbyp":          "byp",
    "riscvlong":         "long",
    "riscvooo":          "OOO",
    "riscvvec":          "vec",
    "riscvvec-chained":  "vec+chain",
}


def short(processor: str) -> str:
    return SHORT_LABEL.get(processor, processor)


# ---------------------------------------------------------------------------
# fig 1: per-kernel cycle counts (4-panel grid, linpack gets log scale)
# ---------------------------------------------------------------------------

def fig_cycles_per_kernel(processors, main_rows) -> Path:
    bench_order = ["vvadd", "saxpy", "daxpy", "linpack"]
    title_map = {
        "vvadd":   "VVADD (32 elements, memory-bound)",
        "saxpy":   "SAXPY (16 elements, single multiply)",
        "daxpy":   "DAXPY (32 elements, multiply-add)",
        "linpack": "LINPACK (16x16 matrix-vector, log scale)",
    }
    fig, axes = plt.subplots(2, 2, figsize=(11, 7.2))
    axes = axes.flatten()

    by_bm = defaultdict(list)
    for r in main_rows:
        if r["passed"]:
            by_bm[r["benchmark"]].append(r)

    proc_order = ["riscvbyp", "riscvlong", "riscvooo", "riscvvec", "riscvvec-chained"]

    for ax, bm in zip(axes, bench_order):
        rows = by_bm.get(bm, [])
        labels, cycles, colors = [], [], []
        for proc in proc_order:
            # pick scalar for non-vec procs, vec for vec procs
            is_vec = next((p["is_vector_capable"] for p in processors if p["name"] == proc), False)
            mode = "vector" if is_vec else "scalar"
            row = next((r for r in rows if r["processor"] == proc and r["mode"] == mode), None)
            if row is None:
                continue
            labels.append(short(proc))
            cycles.append(row["cycles"])
            colors.append(L.proc_color(processors, proc))
        x = np.arange(len(labels))
        bars = ax.bar(x, cycles, color=colors, edgecolor="black", linewidth=0.5, width=0.7)
        for bar, v in zip(bars, cycles):
            ax.text(bar.get_x() + bar.get_width()/2,
                    v * 1.04 if bm != "linpack" else v * 1.1,
                    f"{v}", ha="center", va="bottom", fontsize=9)
        ax.set_xticks(x)
        ax.set_xticklabels(labels, fontsize=10)
        ax.set_ylabel("Cycles")
        ax.set_title(title_map[bm])
        if bm == "linpack":
            ax.set_yscale("log")
            ax.set_ylim(top=max(cycles) * 2.5)
        else:
            ax.set_ylim(0, max(cycles) * 1.18)
    fig.suptitle("Per-kernel cycle counts across processor variants",
                 fontsize=13, fontweight="bold", y=0.995)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    return L.save(fig, "fig1_cycles_per_kernel.png")


# ---------------------------------------------------------------------------
# fig 2: speedup vs riscvbyp baseline
# ---------------------------------------------------------------------------

def fig_speedup(processors, main_rows) -> Path:
    bench_order = ["vvadd", "saxpy", "daxpy", "linpack", "vvmul", "dotprod"]
    proc_order = ["riscvlong", "riscvooo", "riscvvec", "riscvvec-chained"]

    base = {}
    by = defaultdict(dict)
    for r in main_rows:
        if not r["passed"]:
            continue
        if r["processor"] == "riscvbyp" and r["mode"] == "scalar":
            base[r["benchmark"]] = r["cycles"]
    for r in main_rows:
        if not r["passed"]:
            continue
        if r["processor"] not in proc_order:
            continue
        is_vec = next((p["is_vector_capable"] for p in processors if p["name"] == r["processor"]), False)
        if is_vec and r["mode"] != "vector":
            continue
        if not is_vec and r["mode"] != "scalar":
            continue
        if r["benchmark"] not in base or base[r["benchmark"]] == 0:
            continue
        by[r["benchmark"]][r["processor"]] = base[r["benchmark"]] / r["cycles"]

    fig, ax = plt.subplots(figsize=(10, 5))
    x = np.arange(len(bench_order))
    width = 0.20

    for i, proc in enumerate(proc_order):
        offsets = x + (i - 1.5) * width
        vals = [by.get(b, {}).get(proc, 0) for b in bench_order]
        bars = ax.bar(offsets, vals, width,
                      label=L.proc_label(processors, proc),
                      color=L.proc_color(processors, proc),
                      edgecolor="black", linewidth=0.4)
        for bar, v in zip(bars, vals):
            if v > 0:
                ax.text(bar.get_x() + bar.get_width()/2, v, f"{v:.1f}x",
                        ha="center", va="bottom", fontsize=8)

    ax.axhline(1.0, color="black", linewidth=0.6, linestyle="--", alpha=0.5)
    ax.set_xticks(x)
    ax.set_xticklabels(bench_order)
    ax.set_ylabel("Speedup over riscvbyp (scalar)")
    ax.set_title("Speedup over scalar baseline (vector mode where supported)")
    ax.legend(loc="upper left", ncol=2)
    ax.set_ylim(0, max((max(by.get(b, {}).values(), default=0) for b in bench_order)) * 1.18)
    fig.tight_layout()
    return L.save(fig, "fig2_speedup_over_baseline.png")


# ---------------------------------------------------------------------------
# fig 3: daxpy scaling - cycles vs N
# ---------------------------------------------------------------------------

def fig_daxpy_scaling(processors, rows) -> Path:
    series = defaultdict(list)
    for r in rows:
        if not r["passed"]:
            continue
        is_vec = next((p["is_vector_capable"] for p in processors if p["name"] == r["processor"]), False)
        if is_vec and r["mode"] != "vector":
            continue
        if not is_vec and r["mode"] != "scalar":
            continue
        series[r["processor"]].append((r["size"], r["cycles"]))

    fig, ax = plt.subplots(figsize=(8, 5))
    proc_order = ["riscvbyp", "riscvlong", "riscvooo", "riscvvec", "riscvvec-chained"]
    # marker variation + color so overlap lines stay readable
    markers = {"riscvbyp": "o", "riscvlong": "s", "riscvooo": "D",
               "riscvvec": "^", "riscvvec-chained": "v"}
    for proc in proc_order:
        pts = sorted(series.get(proc, []))
        if not pts:
            continue
        xs, ys = zip(*pts)
        ax.plot(xs, ys, marker=markers.get(proc, "o"), linewidth=1.6, markersize=7,
                label=L.proc_label(processors, proc),
                color=L.proc_color(processors, proc))

    ax.set_xscale("log", base=2)
    ax.set_yscale("log", base=2)
    ax.set_xticks([16, 32, 64, 128, 256])
    ax.get_xaxis().set_major_formatter(plt.ScalarFormatter())
    ax.set_xlabel("DAXPY length N")
    ax.set_ylabel("Cycles (log scale)")
    ax.set_title("DAXPY scaling: cycle count versus vector length")
    ax.legend(loc="upper left")
    fig.tight_layout()
    return L.save(fig, "fig3_daxpy_scaling.png")


# ---------------------------------------------------------------------------
# fig 4: linpack mtx size scaling
#   vec + chained overlap exactly (chaining doesnt help reductions).
#   dashed + offset for the redundant series so it stays visible.
# ---------------------------------------------------------------------------

def fig_linpack_scaling(processors, rows) -> Path:
    series = defaultdict(list)
    for r in rows:
        if not r["passed"]:
            continue
        is_vec = next((p["is_vector_capable"] for p in processors if p["name"] == r["processor"]), False)
        if is_vec and r["mode"] != "vector":
            continue
        if not is_vec and r["mode"] != "scalar":
            continue
        series[r["processor"]].append((r["size"], r["cycles"]))

    fig, ax = plt.subplots(figsize=(8.5, 5))
    proc_order = ["riscvbyp", "riscvlong", "riscvooo", "riscvvec", "riscvvec-chained"]
    # overlap lines need diff visual handling
    line_styles = {
        "riscvbyp":          ("o", "-",  1.8),
        "riscvlong":         ("s", "-",  1.6),
        "riscvooo":          ("D", "--", 1.4),  # dashed, overlaps long
        "riscvvec":          ("^", "-",  1.6),
        "riscvvec-chained":  ("v", "--", 1.4),  # dashed, overlaps vec
    }
    for proc in proc_order:
        pts = sorted(series.get(proc, []))
        if not pts:
            continue
        xs, ys = zip(*pts)
        marker, ls, lw = line_styles.get(proc, ("o", "-", 1.6))
        ax.plot(xs, ys, marker=marker, linestyle=ls, linewidth=lw, markersize=7,
                label=L.proc_label(processors, proc),
                color=L.proc_color(processors, proc))

    ax.set_xscale("log", base=2)
    ax.set_yscale("log", base=2)
    ax.set_xticks([4, 8, 16, 32])
    ax.get_xaxis().set_major_formatter(plt.ScalarFormatter())
    ax.set_xlabel("Matrix dimension N (NxN)")
    ax.set_ylabel("Cycles (log scale)")
    ax.set_title("LINPACK scaling: cycle count versus matrix dimension")
    ax.legend(loc="upper left")
    # annotate overlap so it doesnt look like a missing line
    ax.text(0.985, 0.04,
            "OOO and Long overlap;  Vector and Chaining overlap\n"
            "(reductions are not chainable in this design)",
            transform=ax.transAxes, ha="right", va="bottom",
            fontsize=8.5, style="italic", color="#444444",
            bbox=dict(boxstyle="round,pad=0.4", facecolor="#f7f7f7",
                      edgecolor="#cccccc", linewidth=0.5))
    fig.tight_layout()
    return L.save(fig, "fig4_linpack_scaling.png")


# ---------------------------------------------------------------------------
# fig 5: instr count contrast (label collision fixed)
# ---------------------------------------------------------------------------

def fig_inst_count(processors, main_rows) -> Path:
    bench_order = ["vvadd", "saxpy", "daxpy", "linpack"]
    fig, ax = plt.subplots(figsize=(8.5, 5))
    x = np.arange(len(bench_order))
    width = 0.35

    scalar = []
    vector = []
    for b in bench_order:
        s_row = next((r for r in main_rows if r["benchmark"] == b
                      and r["processor"] == "riscvbyp" and r["mode"] == "scalar"
                      and r["passed"]), None)
        v_row = next((r for r in main_rows if r["benchmark"] == b
                      and r["processor"] == "riscvvec" and r["mode"] == "vector"
                      and r["passed"]), None)
        scalar.append(s_row["instructions"] if s_row else 0)
        vector.append(v_row["instructions"] if v_row else 0)

    bars1 = ax.bar(x - width/2, scalar, width, label="Scalar (riscvbyp)",
                   color="#777777", edgecolor="black", linewidth=0.4)
    bars2 = ax.bar(x + width/2, vector, width, label="Vector (riscvvec)",
                   color="#1f6f8b", edgecolor="black", linewidth=0.4)
    # val labels go inside tops of bars so they dont collide with the
    # speedup-ratio annot drawn above the pair.
    for bar, v in zip(bars1, scalar):
        ax.text(bar.get_x() + bar.get_width()/2, v * 0.94, f"{v}",
                ha="center", va="top", fontsize=8, color="white")
    for bar, v in zip(bars2, vector):
        ax.text(bar.get_x() + bar.get_width()/2, v * 0.94, f"{v}",
                ha="center", va="top", fontsize=8, color="white")
    for i, b in enumerate(bench_order):
        if scalar[i] and vector[i]:
            ratio = scalar[i] / vector[i]
            ymax = max(scalar[i], vector[i])
            ax.text(x[i], ymax * 1.55, f"{ratio:.1f}x\nfewer",
                    ha="center", va="center", fontsize=9, fontweight="bold",
                    color="#b04a3f")

    ax.set_xticks(x)
    ax.set_xticklabels(bench_order)
    ax.set_ylabel("Dynamic instructions retired (log scale)")
    ax.set_yscale("log")
    ax.set_ylim(top=max(scalar) * 4)
    ax.set_title("Vector encoding amortizes fetch and decode across many elements")
    ax.legend(loc="lower right")
    fig.tight_layout()
    return L.save(fig, "fig5_instruction_count.png")


# ---------------------------------------------------------------------------
# fig 6: nrg breakdown (cleaner title, consistent y-labels)
# ---------------------------------------------------------------------------

def fig_energy_breakdown(processors, main_rows, benchmarks_cfg) -> Path:
    bench_order = ["vvadd", "saxpy", "daxpy", "linpack"]
    profiles = {bm["name"]: lookup_profile(bm["name"]) for bm in benchmarks_cfg["benchmarks"]
                if bm["name"] in bench_order}

    fig, axes = plt.subplots(1, 4, figsize=(13, 4.6), sharey=False)
    component_colors = {"overhead": "#777777", "compute": "#1f6f8b",
                        "memory":   "#9c528b", "idle":    "#cccccc"}

    for ax, bm in zip(axes, bench_order):
        prof = profiles[bm]
        if prof is None:
            ax.set_visible(False)
            continue
        s_row = next((r for r in main_rows if r["benchmark"] == bm
                      and r["processor"] == "riscvbyp" and r["mode"] == "scalar"
                      and r["passed"]), None)
        v_row = next((r for r in main_rows if r["benchmark"] == bm
                      and r["processor"] == "riscvvec" and r["mode"] == "vector"
                      and r["passed"]), None)
        if s_row is None or v_row is None:
            continue
        s_e = estimate_energy(cycles=s_row["cycles"], instructions=s_row["instructions"],
                              profile=prof, is_vector_mode=False)
        vec_disp = next((bm2.get("vec_dispatches") for bm2 in benchmarks_cfg["benchmarks"]
                         if bm2["name"] == bm), None)
        v_e = estimate_energy(cycles=v_row["cycles"], instructions=v_row["instructions"],
                              profile=prof, is_vector_mode=True,
                              num_vec_dispatches=vec_disp)
        labels = ["Scalar", "Vector"]
        bottoms = np.zeros(2)
        for comp in ("overhead", "compute", "memory", "idle"):
            vals = np.array([s_e.as_dict()[comp], v_e.as_dict()[comp]])
            ax.bar(labels, vals, bottom=bottoms, label=comp.capitalize(),
                   color=component_colors[comp], edgecolor="black", linewidth=0.3)
            bottoms += vals
        ax.set_title(bm)
        ax.set_ylabel("Energy (arb. units)")
        s_t = s_e.total
        v_t = v_e.total
        if v_t > 0:
            ax.text(0.5, max(s_t, v_t) * 1.06,
                    f"{s_t/v_t:.2f}x lower", ha="center",
                    fontsize=9, fontweight="bold", color="#b04a3f",
                    transform=ax.transData)
        ax.set_ylim(0, max(s_t, v_t) * 1.2)

    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=4, bbox_to_anchor=(0.5, -0.02))
    fig.suptitle("Energy decomposition: vector mode shrinks the fetch/decode component",
                 fontsize=12, fontweight="bold")
    fig.tight_layout(rect=[0, 0.04, 1, 0.95])
    return L.save(fig, "fig6_energy_breakdown.png")


# ---------------------------------------------------------------------------
# fig 7: energy-delay product
# ---------------------------------------------------------------------------

def fig_edp(processors, main_rows, benchmarks_cfg) -> Path:
    bench_order = ["vvadd", "saxpy", "daxpy", "linpack"]
    proc_order = ["riscvbyp", "riscvlong", "riscvooo", "riscvvec", "riscvvec-chained"]

    profiles = {bm["name"]: lookup_profile(bm["name"]) for bm in benchmarks_cfg["benchmarks"]
                if bm["name"] in bench_order}
    vec_disp_map = {bm["name"]: bm.get("vec_dispatches") for bm in benchmarks_cfg["benchmarks"]}

    fig, ax = plt.subplots(figsize=(10.5, 5))
    x = np.arange(len(bench_order))
    width = 0.16

    for i, proc in enumerate(proc_order):
        is_vec = next((p["is_vector_capable"] for p in processors if p["name"] == proc), False)
        edps = []
        for bm in bench_order:
            prof = profiles.get(bm)
            row = next((r for r in main_rows if r["benchmark"] == bm
                        and r["processor"] == proc
                        and r["mode"] == ("vector" if is_vec else "scalar")
                        and r["passed"]), None)
            if row is None or prof is None:
                edps.append(0)
                continue
            e = estimate_energy(cycles=row["cycles"], instructions=row["instructions"],
                                profile=prof, is_vector_mode=is_vec,
                                num_vec_dispatches=vec_disp_map.get(bm) if is_vec else None)
            edps.append(e.total * row["cycles"])
        offsets = x + (i - 2) * width
        ax.bar(offsets, edps, width,
               label=L.proc_label(processors, proc),
               color=L.proc_color(processors, proc),
               edgecolor="black", linewidth=0.4)

    ax.set_xticks(x)
    ax.set_xticklabels(bench_order)
    ax.set_ylabel("Energy x Delay (arb. units, log scale)")
    ax.set_yscale("log")
    ax.set_title("Energy-Delay Product (lower is better)")
    ax.legend(loc="upper left", ncol=2)
    fig.tight_layout()
    return L.save(fig, "fig7_edp.png")


# ---------------------------------------------------------------------------
# fig 8: cmd queue depth sweep, w/ explanatory annots
# ---------------------------------------------------------------------------

def fig_queue_sweep(rows) -> Path:
    series = defaultdict(list)
    for r in rows:
        if not r["passed"]:
            continue
        series[r["benchmark"]].append((r["queue_depth"], r["cycles"]))

    fig, axes = plt.subplots(1, 2, figsize=(11.5, 4.7), sharey=False)
    pipelined_pts = sorted(series.get("linpack-pipelined", []))
    standard_benches = ["vvadd", "saxpy", "daxpy", "linpack"]

    if pipelined_pts:
        xs, ys = zip(*pipelined_pts)
        axes[0].plot(xs, ys, marker="o", linewidth=2, color="#b04a3f", markersize=8)
    axes[0].set_xscale("log", base=2)
    axes[0].set_xticks([2, 4, 8, 16])
    axes[0].get_xaxis().set_major_formatter(plt.ScalarFormatter())
    axes[0].set_xlabel("Command queue depth")
    axes[0].set_ylabel("Cycles")
    axes[0].set_title("Pipelined LINPACK\n(no per-row VFENCE)")
    axes[0].text(0.5, 0.92,
                 "Vector unit is the bottleneck;\n"
                 "scalar dispatch never has\n"
                 "to wait, so depth doesn't matter.",
                 transform=axes[0].transAxes, ha="center", va="top",
                 fontsize=9, style="italic", color="#444444",
                 bbox=dict(boxstyle="round,pad=0.4", facecolor="#fff7f3",
                           edgecolor="#d8a99a", linewidth=0.5))

    colors = {"vvadd": "#3a7ca5", "saxpy": "#9c528b", "daxpy": "#1f6f8b", "linpack": "#b04a3f"}
    for bm in standard_benches:
        pts = sorted(series.get(bm, []))
        if not pts:
            continue
        xs, ys = zip(*pts)
        axes[1].plot(xs, ys, marker="o", linewidth=1.6, label=bm,
                     color=colors.get(bm, "#444"), markersize=7)
    axes[1].set_xscale("log", base=2)
    axes[1].set_xticks([2, 4, 8, 16])
    axes[1].get_xaxis().set_major_formatter(plt.ScalarFormatter())
    axes[1].set_xlabel("Command queue depth")
    axes[1].set_ylabel("Cycles")
    axes[1].set_title("Standard kernels\n(VFENCE drains queue every batch)")
    axes[1].legend(loc="center right")
    axes[1].text(0.5, 0.5,
                 "Each kernel ends in VFENCE,\n"
                 "so the queue never reaches\n"
                 "more than ~5 entries occupied.",
                 transform=axes[1].transAxes, ha="center", va="center",
                 fontsize=9, style="italic", color="#444444",
                 bbox=dict(boxstyle="round,pad=0.4", facecolor="#f7f7f7",
                           edgecolor="#cccccc", linewidth=0.5))

    fig.suptitle("Command queue depth has no effect on the workloads tested",
                 fontsize=12, fontweight="bold", y=1.00)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    return L.save(fig, "fig8_queue_depth.png")


# ---------------------------------------------------------------------------
# fig 9 (NEW): chain-depth study - does chaining actually help?
# ---------------------------------------------------------------------------

def fig_chain_depth(processors, rows) -> Path:
    series = defaultdict(list)
    for r in rows:
        if not r["passed"]:
            continue
        series[r["processor"]].append((r["size"], r["cycles"]))

    fig, ax = plt.subplots(figsize=(8.5, 5))
    proc_order = ["riscvvec", "riscvvec-chained"]
    markers = {"riscvvec": "^", "riscvvec-chained": "v"}
    for proc in proc_order:
        pts = sorted(series.get(proc, []))
        if not pts:
            continue
        xs, ys = zip(*pts)
        ax.plot(xs, ys, marker=markers.get(proc, "o"), linewidth=1.8, markersize=8,
                label=L.proc_label(processors, proc),
                color=L.proc_color(processors, proc))

    ax.set_xticks([1, 2, 3, 4, 5, 6])
    ax.set_xlabel("Number of consecutive RAW-dependent VVADDs")
    ax.set_ylabel("Cycles")
    ax.set_title("Chain-depth study: chaining captures every other op as a producer/consumer pair")
    ax.legend(loc="upper left")
    # annotate slope insight
    ax.text(0.985, 0.04,
            "Master slope: ~9 cycles per added op\n"
            "Chained slope: ~5 cycles per added op\n"
            "(first op runs solo because the second has\n"
            "not yet been pushed when the first dequeues)",
            transform=ax.transAxes, ha="right", va="bottom",
            fontsize=8.5, style="italic", color="#444444",
            bbox=dict(boxstyle="round,pad=0.4", facecolor="#f7f7f7",
                      edgecolor="#cccccc", linewidth=0.5))
    fig.tight_layout()
    return L.save(fig, "fig9_chain_depth.png")


# ---------------------------------------------------------------------------
# fig 10 (NEW): C ubmark cycles across procs
# ---------------------------------------------------------------------------

def fig_ubmarks(processors, main_rows) -> Path:
    ubmark_order = ["ubmark-vvadd", "ubmark-cmplx-mult", "ubmark-bin-search", "ubmark-masked-filter"]
    proc_order = ["riscvbyp", "riscvlong", "riscvooo", "riscvvec", "riscvvec-chained"]

    fig, axes = plt.subplots(2, 2, figsize=(11, 7))
    axes = axes.flatten()

    for ax, bm in zip(axes, ubmark_order):
        labels, cycles, colors = [], [], []
        for proc in proc_order:
            row = next((r for r in main_rows if r["benchmark"] == bm
                        and r["processor"] == proc
                        and r["mode"] == "scalar"
                        and r["passed"]), None)
            if row is None:
                continue
            labels.append(short(proc))
            cycles.append(row["cycles"])
            colors.append(L.proc_color(processors, proc))
        x = np.arange(len(labels))
        bars = ax.bar(x, cycles, color=colors, edgecolor="black", linewidth=0.5, width=0.7)
        for bar, v in zip(bars, cycles):
            ax.text(bar.get_x() + bar.get_width()/2, v * 1.04, f"{v}",
                    ha="center", va="bottom", fontsize=9)
        ax.set_xticks(x)
        ax.set_xticklabels(labels, fontsize=10)
        ax.set_ylabel("Cycles")
        ax.set_title(bm)
        ax.set_ylim(0, max(cycles) * 1.15)

    fig.suptitle("Compiled C microbenchmarks: cycle counts across processor variants",
                 fontsize=13, fontweight="bold", y=0.995)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    return L.save(fig, "fig10_ubmarks.png")


# ---------------------------------------------------------------------------
# fig 11: FLOPs/cycle comparison across kernels (scalar vs vector)
# ---------------------------------------------------------------------------

def fig_flops_per_cycle(processors, main_rows, benchmarks_cfg) -> Path:
    bench_order = ["vvadd", "saxpy", "daxpy", "linpack", "vvmul", "dotprod"]
    flops_map = {bm["name"]: bm.get("flops", 0) for bm in benchmarks_cfg["benchmarks"]}

    scalar_fpc, vector_fpc = [], []
    labels = []
    for bm in bench_order:
        flops = flops_map.get(bm, 0)
        if not flops:
            continue
        s_row = next((r for r in main_rows if r["benchmark"] == bm
                      and r["processor"] == "riscvbyp" and r["mode"] == "scalar"
                      and r["passed"]), None)
        v_row = next((r for r in main_rows if r["benchmark"] == bm
                      and r["processor"] == "riscvvec" and r["mode"] == "vector"
                      and r["passed"]), None)
        if s_row is None or v_row is None:
            continue
        labels.append(bm)
        scalar_fpc.append(flops / s_row["cycles"])
        vector_fpc.append(flops / v_row["cycles"])

    x = np.arange(len(labels))
    width = 0.38
    fig, ax = plt.subplots(figsize=(10, 5))
    bars1 = ax.bar(x - width/2, scalar_fpc, width, label="Scalar (riscvbyp)",
                   color="#777777", edgecolor="black", linewidth=0.4)
    bars2 = ax.bar(x + width/2, vector_fpc, width, label="Vector (riscvvec)",
                   color="#1f6f8b", edgecolor="black", linewidth=0.4)
    for bar, v in zip(bars1, scalar_fpc):
        ax.text(bar.get_x() + bar.get_width()/2, v + 0.003, f"{v:.3f}",
                ha="center", va="bottom", fontsize=8.5)
    for bar, v in zip(bars2, vector_fpc):
        ax.text(bar.get_x() + bar.get_width()/2, v + 0.003, f"{v:.3f}",
                ha="center", va="bottom", fontsize=8.5)
    for i in range(len(labels)):
        if scalar_fpc[i] > 0:
            ratio = vector_fpc[i] / scalar_fpc[i]
            ymax = max(scalar_fpc[i], vector_fpc[i])
            ax.text(x[i], ymax * 1.35, f"{ratio:.1f}x",
                    ha="center", va="center", fontsize=9, fontweight="bold",
                    color="#b04a3f")
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_ylabel("FLOPs / cycle")
    ax.set_title("Compute efficiency: FLOPs per cycle (scalar vs vector)")
    ax.legend(loc="upper left")
    ax.set_ylim(0, max(vector_fpc) * 1.55)
    fig.tight_layout()
    return L.save(fig, "fig11_flops_per_cycle.png")


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------

def main() -> int:
    L.configure_style()
    processors = L.load_processors()
    benchmarks_cfg = L.load_benchmarks()

    main_rows = L.load_csv("main.csv")
    daxpy_rows = L.load_csv("daxpy_n.csv")
    linpack_rows = L.load_csv("linpack_size.csv")
    queue_rows = L.load_csv("sweep_queue.csv")
    chain_rows = L.load_csv("chain_depth.csv")

    figs = [
        fig_cycles_per_kernel(processors, main_rows),
        fig_speedup(processors, main_rows),
        fig_daxpy_scaling(processors, daxpy_rows),
        fig_linpack_scaling(processors, linpack_rows),
        fig_inst_count(processors, main_rows),
        fig_energy_breakdown(processors, main_rows, benchmarks_cfg),
        fig_edp(processors, main_rows, benchmarks_cfg),
        fig_queue_sweep(queue_rows),
        fig_chain_depth(processors, chain_rows),
        fig_ubmarks(processors, main_rows),
        fig_flops_per_cycle(processors, main_rows, benchmarks_cfg),
    ]
    for p in figs:
        print(f"wrote {p.relative_to(L.THIS_DIR)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
