#!/usr/bin/env python3
"""
Generate all 'need-to-make' presentation graphics for the vector coprocessor slideshow.
Outputs to perf_results/slide_*.png

Figures produced:
  slide_s1_code_compare.png   — scalar loop vs vector code side-by-side (Slide 1)
  slide_s1_timeline.png       — decoupled execution timeline (Slide 1/3)
  slide_s2_encoding.png       — 32-bit instruction format diagram (Slide 2)
  slide_s2_categories.png     — instruction category breakdown (Slide 2)
  slide_s3_block_diagram.png  — architecture block diagram (Slide 3)
  slide_s3_fsm.png            — VecCtrl FSM state diagram (Slide 3)
"""

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import matplotlib.patheffects as pe
from pathlib import Path

OUT = Path(__file__).parent / "perf_results"
OUT.mkdir(exist_ok=True)

# ── Shared palette (matches validate_perf.py) ──────────────────────────────
C_SCALAR  = "#4878CF"   # blue  – scalar
C_VEC     = "#E87722"   # orange – vector
C_MEM     = "#5BAD72"   # green – memory ops
C_ARITH   = "#CF4A58"   # red   – arithmetic ops
C_QUEUE   = "#9B59B6"   # purple – queue / dispatch
C_CFG     = "#1ABC9C"   # teal  – config / FSM
C_GRAY    = "#8090A8"
C_LIGHT   = "#F7F9FC"
C_DARK    = "#2C3E50"
C_WHITE   = "#FFFFFF"

TITLE_FS  = 14
LABEL_FS  = 11
SMALL_FS  = 9

def savefig(fig, name):
    path = OUT / name
    fig.savefig(path, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"  saved  {path.name}")


# ═══════════════════════════════════════════════════════════════════════════
# Slide 1 — Code comparison: scalar DAXPY loop vs vectorized
# ═══════════════════════════════════════════════════════════════════════════

def make_code_compare():
    fig, axes = plt.subplots(1, 2, figsize=(14, 6.5), facecolor=C_DARK)
    fig.suptitle("DAXPY:  y[i] = a × x[i] + y[i]  for i = 0 … 31",
                 color=C_WHITE, fontsize=TITLE_FS + 1, fontweight="bold", y=0.97)

    scalar_lines = [
        ("        la   x10, x_data     # x array ptr",        False),
        ("        la   x11, y_data     # y array ptr",        False),
        ("        li   x12, 3          # scalar a",           False),
        ("        li   x13, 32         # loop count",         False),
        ("",                                                   False),
        ("loop:   lw   x14, 0(x10)    # load x[i]",          True),
        ("        lw   x15, 0(x11)    # load y[i]",          True),
        ("        mul  x16, x14, x12  # a*x[i]  ← STALL",   True),
        ("                            # (32 cycles!)",        True),
        ("        add  x16, x16, x15  # +y[i]",              True),
        ("        sw   x16, 0(x11)    # store",               True),
        ("        addi x10, x10, 4    # bump ptr",            True),
        ("        addi x11, x11, 4    # bump ptr",            True),
        ("        addi x13, x13, -1   # decrement ctr",       True),
        ("        bne  x13, x0, loop  # branch",              True),
        ("",                                                   False),
        ("# repeats × 32 iterations",                         False),
    ]

    vec_lines = [
        ("        la   x10, x_data",   False),
        ("        la   x11, y_data",   False),
        ("        li   x12, 3",        False),
        ("        li   x13, 32",       False),
        ("        SETVL  x14, x13     # VL = 32",  False),
        ("        VFENCE",             False),
        ("        CVM                 # mask = all 1s", False),
        ("",                           False),
        ("        VLW   v0, x10       # load x[0:31]",  True),
        ("        VLW   v1, x11       # load y[0:31]",  True),
        ("        VSMUL v2, v0, x12   # v2 = a * v0",   True),
        ("        VVADD v3, v2, v1    # v3 = v2 + v1",  True),
        ("        VSW   v3, x11       # store y[0:31]", True),
        ("        VFENCE              # sync",           False),
        ("",                           False),
        ("# 5 vector instructions cover all 32 elements", False),
    ]

    subtitles = [
        ("Scalar Baseline", "1475 cycles   |   322 instructions", C_SCALAR),
        ("Vectorized",      " 274 cycles   |    44 instructions   →  5.4× faster", C_VEC),
    ]

    for ax, lines, (title, stat, color) in zip(axes, [scalar_lines, vec_lines], subtitles):
        ax.set_facecolor("#1A2332")
        ax.set_xlim(0, 1)
        ax.set_ylim(0, len(lines) + 2.5)
        ax.axis("off")

        # Title band
        ax.add_patch(FancyBboxPatch((0, len(lines) + 1.2), 1, 1.1,
                                    boxstyle="round,pad=0.02",
                                    facecolor=color, alpha=0.85, linewidth=0))
        ax.text(0.5, len(lines) + 1.75, title,
                ha="center", va="center", color=C_WHITE,
                fontsize=LABEL_FS + 1, fontweight="bold", fontfamily="monospace")
        ax.text(0.5, len(lines) + 1.3, stat,
                ha="center", va="center", color=C_WHITE,
                fontsize=SMALL_FS, fontfamily="monospace")

        for row, (text, in_loop) in enumerate(lines):
            y = len(lines) - row - 0.5
            if in_loop:
                ax.add_patch(FancyBboxPatch((0.01, y - 0.38), 0.98, 0.75,
                                            boxstyle="round,pad=0.01",
                                            facecolor=color, alpha=0.13,
                                            linewidth=0))
            # Highlight MUL stall line
            fc = "#FF6B6B" if "STALL" in text else (C_WHITE if not in_loop else "#DDEEFF")
            ax.text(0.03, y, text, ha="left", va="center",
                    color=fc, fontsize=8.5, fontfamily="monospace")

        # Loop bracket annotation for scalar
        if title.startswith("Scalar"):
            n_loop = sum(1 for _, il in lines if il)
            top_loop = len(lines) - next(i for i,(_, il) in enumerate(lines) if il) - 0.5
            bot_loop = len(lines) - (len(lines) - 1 - next(i for i,(_, il) in reversed(list(enumerate(lines))) if il)) - 0.5
            ax.annotate("", xy=(0.995, bot_loop - 0.3), xytext=(0.995, top_loop + 0.3),
                        arrowprops=dict(arrowstyle="-|>", color="#FF6B6B", lw=1.5))
            ax.text(1.0, (top_loop + bot_loop) / 2, "×32",
                    ha="left", va="center", color="#FF6B6B",
                    fontsize=SMALL_FS, fontweight="bold")
        else:
            # Brace around vector instructions
            top_v = len(lines) - next(i for i,(_, il) in enumerate(lines) if il) - 0.5
            bot_v = len(lines) - (len(lines) - 1 - next(i for i,(_, il) in reversed(list(enumerate(lines))) if il)) - 0.5
            ax.annotate("", xy=(0.995, bot_v - 0.3), xytext=(0.995, top_v + 0.3),
                        arrowprops=dict(arrowstyle="-|>", color=C_VEC, lw=1.5))
            ax.text(1.0, (top_v + bot_v) / 2, "1×",
                    ha="left", va="center", color=C_VEC,
                    fontsize=SMALL_FS, fontweight="bold")

    fig.tight_layout(rect=[0, 0, 1, 0.95])
    savefig(fig, "slide_s1_code_compare.png")


# ═══════════════════════════════════════════════════════════════════════════
# Slide 1 — Decoupled execution timeline
# ═══════════════════════════════════════════════════════════════════════════

def make_timeline():
    """
    Gantt-style chart showing how the scalar core dispatches 5 vector commands
    into the queue, then the vector unit processes them while the scalar core
    does setup work, then stalls at VFENCE.
    """
    fig, ax = plt.subplots(figsize=(14, 5), facecolor=C_LIGHT)
    ax.set_facecolor(C_LIGHT)

    # Layout: VL=32, 5 convoys, show first ~90 cycles
    VL = 32
    CYCLES = 185
    DISPATCH_COST = 1  # 1 cycle per dispatch (command enqueue)
    SETUP_BEFORE  = 12  # cycles of scalar setup before first VLW

    # Vector commands and their start cycles in the vector unit
    vec_cmds = [
        ("VLW v0",   "mem"),
        ("VLW v1",   "mem"),
        ("VSMUL v2", "arith"),
        ("VVADD v3", "arith"),
        ("VSW v3",   "mem"),
    ]
    vec_start = SETUP_BEFORE + len(vec_cmds) + 4  # vector unit starts after last dispatch + queue latency
    vec_intervals = []
    t = vec_start
    for name, kind in vec_cmds:
        vec_intervals.append((name, kind, t, t + VL))
        t += VL
    vec_end = t  # when vector unit goes idle (VFENCE satisfied)

    # Scalar timeline events
    # [start, end, label, color]
    scalar_events = []
    # Setup (la, li, SETVL, VFENCE, CVM, VFENCE)
    scalar_events.append((0, SETUP_BEFORE, "Scalar setup\n(la, li, SETVL, CVM)", C_SCALAR))
    # Dispatch window
    for i, (name, _) in enumerate(vec_cmds):
        t0 = SETUP_BEFORE + i * DISPATCH_COST
        scalar_events.append((t0, t0 + DISPATCH_COST, f"DISPATCH\n{name}", C_QUEUE))
    # VFENCE issued right after last dispatch
    vfence_issued = SETUP_BEFORE + len(vec_cmds)
    scalar_events.append((vfence_issued, vec_end, "VFENCE\n(stall)", "#E74C3C"))
    # After vector done: post-processing
    scalar_events.append((vec_end, vec_end + 15, "Scalar verify\n& finish", C_SCALAR))

    # Queue depth trace: increases on each dispatch, decreases as vector unit completes
    queue_events = []
    depth = 0
    for i in range(len(vec_cmds)):
        dispatch_t = SETUP_BEFORE + i * DISPATCH_COST
        queue_events.append((dispatch_t, dispatch_t + 1, min(depth + 1, 4)))
        depth = min(depth + 1, 4)
    for i, (_, _, vs, ve) in enumerate(vec_intervals):
        queue_events.append((ve, ve + 1, max(depth - 1, 0)))
        depth = max(depth - 1, 0)

    # ── Row positions ──
    ROW_SCALAR = 2.5
    ROW_QUEUE  = 1.4
    ROW_VEC    = 0.3
    ROW_H      = 0.75

    # Draw scalar timeline
    for (t0, t1, label, color) in scalar_events:
        ax.add_patch(FancyBboxPatch((t0, ROW_SCALAR - ROW_H/2), t1 - t0, ROW_H,
                                    boxstyle="round,pad=1", linewidth=0.5,
                                    edgecolor="white", facecolor=color, alpha=0.88))
        mid = (t0 + t1) / 2
        fontsize = 7 if (t1 - t0) < 8 else 8
        ax.text(mid, ROW_SCALAR, label, ha="center", va="center",
                color="white", fontsize=fontsize, fontweight="bold",
                multialignment="center")

    # Draw vector unit timeline
    for name, kind, t0, t1 in vec_intervals:
        color = C_MEM if kind == "mem" else C_ARITH
        ax.add_patch(FancyBboxPatch((t0, ROW_VEC - ROW_H/2), t1 - t0, ROW_H,
                                    boxstyle="round,pad=1", linewidth=0.5,
                                    edgecolor="white", facecolor=color, alpha=0.88))
        mid = (t0 + t1) / 2
        ax.text(mid, ROW_VEC + 0.12, name,
                ha="center", va="center", color="white",
                fontsize=8, fontweight="bold")
        ax.text(mid, ROW_VEC - 0.18, f"{t1-t0} cy",
                ha="center", va="center", color="white", fontsize=7)

    # Draw idle region in vector unit before first command
    ax.add_patch(FancyBboxPatch((0, ROW_VEC - ROW_H/2), vec_start, ROW_H,
                                boxstyle="round,pad=1", linewidth=0.5,
                                edgecolor=C_GRAY, facecolor=C_GRAY, alpha=0.25,
                                linestyle="--"))
    ax.text(vec_start / 2, ROW_VEC, "IDLE", ha="center", va="center",
            color=C_GRAY, fontsize=8, style="italic")

    # Draw queue depth bar
    q_t = [0] + [SETUP_BEFORE + i for i in range(len(vec_cmds))]
    q_d = [0] + list(range(1, len(vec_cmds) + 1))
    q_t2 = [SETUP_BEFORE + len(vec_cmds)] + [v[2] + VL for v in vec_intervals]
    q_d2 = [len(vec_cmds)] + list(range(len(vec_cmds) - 1, -1, -1))
    all_t = q_t + q_t2
    all_d = q_d + q_d2
    for i in range(len(all_t) - 1):
        depth_val = all_d[i]
        bar_h = 0.65 * depth_val / 4
        if bar_h > 0:
            ax.add_patch(mpatches.Rectangle(
                (all_t[i], ROW_QUEUE - 0.35), all_t[i+1] - all_t[i], bar_h,
                facecolor=C_QUEUE, alpha=0.7, linewidth=0))

    ax.add_patch(mpatches.Rectangle((0, ROW_QUEUE - 0.35), CYCLES, 0.65,
                                     fill=False, edgecolor=C_QUEUE, linewidth=1,
                                     linestyle="--", alpha=0.5))
    ax.text(-3, ROW_QUEUE, "Queue\ndepth", ha="right", va="center",
            fontsize=8, color=C_QUEUE, fontweight="bold")

    # VFENCE marker line
    ax.axvline(vfence_issued, color="#E74C3C", linewidth=1.5, linestyle=":", alpha=0.8)
    ax.text(vfence_issued + 0.5, 3.45, "VFENCE issued",
            color="#E74C3C", fontsize=8, rotation=0)

    ax.axvline(vec_end, color=C_CFG, linewidth=1.5, linestyle=":", alpha=0.8)
    ax.text(vec_end + 0.5, 3.45, "vector idle\n→ scalar resumes",
            color=C_CFG, fontsize=8)

    # Row labels
    for y, label in [(ROW_SCALAR, "Scalar core"), (ROW_VEC, "Vector unit")]:
        ax.text(-3, y, label, ha="right", va="center", fontsize=9,
                fontweight="bold", color=C_DARK)

    # Legend
    leg = [
        mpatches.Patch(color=C_SCALAR,  label="Scalar execution"),
        mpatches.Patch(color=C_QUEUE,   label="Dispatch / Queue"),
        mpatches.Patch(color=C_MEM,     label="Vector memory op"),
        mpatches.Patch(color=C_ARITH,   label="Vector arithmetic"),
        mpatches.Patch(color="#E74C3C", label="VFENCE stall"),
    ]
    ax.legend(handles=leg, loc="upper right", fontsize=8, framealpha=0.9,
              ncol=5, bbox_to_anchor=(1, 1.12))

    ax.set_xlim(-8, CYCLES + 5)
    ax.set_ylim(-0.2, 4.0)
    ax.set_xlabel("Cycle", fontsize=LABEL_FS)
    ax.set_title("Decoupled Execution: DAXPY (VL=32)   —   Scalar dispatches while vector computes",
                 fontsize=TITLE_FS, fontweight="bold", pad=16)

    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_visible(False)
    ax.set_yticks([])
    ax.grid(axis="x", alpha=0.2, linewidth=0.5)

    fig.tight_layout()
    savefig(fig, "slide_s1_timeline.png")


# ═══════════════════════════════════════════════════════════════════════════
# Slide 2 — Instruction encoding diagram
# ═══════════════════════════════════════════════════════════════════════════

def make_encoding():
    fig, axes = plt.subplots(3, 1, figsize=(13, 6.5), facecolor=C_LIGHT)
    fig.suptitle("Vector Instruction Encoding  —  Custom-0 opcode (0x0B)",
                 fontsize=TITLE_FS, fontweight="bold")

    fields = [
        # (bit_hi, bit_lo, label, sublabel, color)
        (31, 25, "funct7",  "operation\nwithin category",  C_ARITH),
        (24, 20, "vs2/rs2", "src vector 2\nor scalar reg",  C_VEC),
        (19, 15, "vs1/rs1", "src vector 1\nor scalar reg",  C_SCALAR),
        (14, 12, "funct3",  "instruction\ncategory",        C_QUEUE),
        (11,  7, "vd/rd",   "dest vector\nor scalar reg",   C_MEM),
        ( 6,  0, "opcode",  "0x0B\n(custom-0)",             C_CFG),
    ]

    ax = axes[0]
    ax.set_facecolor(C_LIGHT)
    ax.set_xlim(0, 32)
    ax.set_ylim(0, 2.2)
    ax.axis("off")

    # Draw bit fields
    for hi, lo, label, sublabel, color in fields:
        width = hi - lo + 1
        x_start = 31 - hi  # flip: bit 31 is leftmost
        ax.add_patch(FancyBboxPatch((x_start + 0.05, 0.7), width - 0.1, 1.1,
                                    boxstyle="round,pad=0.1",
                                    facecolor=color, alpha=0.85, linewidth=1,
                                    edgecolor="white"))
        mid_x = x_start + width / 2
        ax.text(mid_x, 1.45, label, ha="center", va="center",
                color="white", fontsize=9, fontweight="bold")
        ax.text(mid_x, 0.2, sublabel, ha="center", va="center",
                color=color, fontsize=7.5, multialignment="center")

        # Bit range labels
        ax.text(x_start + 0.1, 1.85, str(hi), ha="left", va="center",
                color=C_DARK, fontsize=7.5)
        ax.text(x_start + width - 0.1, 1.85, str(lo), ha="right", va="center",
                color=C_DARK, fontsize=7.5)

    ax.set_title("32-bit instruction word", fontsize=LABEL_FS, loc="left", pad=4)

    # ── Example: VVADD v2, v0, v1 ──
    ax2 = axes[1]
    ax2.set_facecolor(C_LIGHT)
    ax2.set_xlim(0, 32)
    ax2.set_ylim(0, 1.8)
    ax2.axis("off")

    example = [
        (31, 25, "0000000",  "funct7=0\n(VVADD)",  C_ARITH),
        (24, 20, "00001",    "vs2=v1",              C_VEC),
        (19, 15, "00000",    "vs1=v0",              C_SCALAR),
        (14, 12, "000",      "VV_ARITH",            C_QUEUE),
        (11,  7, "00010",    "vd=v2",               C_MEM),
        ( 6,  0, "0001011",  "0x0B",                C_CFG),
    ]

    for hi, lo, bits, label, color in example:
        width = hi - lo + 1
        x_start = 31 - hi
        ax2.add_patch(FancyBboxPatch((x_start + 0.05, 0.65), width - 0.1, 0.85,
                                     boxstyle="round,pad=0.1",
                                     facecolor=color, alpha=0.75, linewidth=1,
                                     edgecolor="white"))
        mid_x = x_start + width / 2
        ax2.text(mid_x, 1.1, bits, ha="center", va="center",
                 color="white", fontsize=8.5, fontweight="bold", fontfamily="monospace")
        ax2.text(mid_x, 0.25, label, ha="center", va="center",
                 color=color, fontsize=7.5, multialignment="center")

    ax2.set_title("Example:  VVADD v2, v0, v1", fontsize=LABEL_FS, loc="left", pad=4)

    # ── Example: VSADD v3, v1, x5 (vector-scalar) ──
    ax3 = axes[2]
    ax3.set_facecolor(C_LIGHT)
    ax3.set_xlim(0, 32)
    ax3.set_ylim(0, 1.8)
    ax3.axis("off")

    example2 = [
        (31, 25, "0000000",  "funct7=0\n(VSADD)",   C_ARITH),
        (24, 20, "00101",    "rs2=x5\n(scalar)",     C_VEC),
        (19, 15, "00001",    "vs1=v1",               C_SCALAR),
        (14, 12, "001",      "VS_ARITH",             C_QUEUE),
        (11,  7, "00011",    "vd=v3",                C_MEM),
        ( 6,  0, "0001011",  "0x0B",                 C_CFG),
    ]

    for hi, lo, bits, label, color in example2:
        width = hi - lo + 1
        x_start = 31 - hi
        ax3.add_patch(FancyBboxPatch((x_start + 0.05, 0.65), width - 0.1, 0.85,
                                     boxstyle="round,pad=0.1",
                                     facecolor=color, alpha=0.75, linewidth=1,
                                     edgecolor="white"))
        mid_x = x_start + width / 2
        ax3.text(mid_x, 1.1, bits, ha="center", va="center",
                 color="white", fontsize=8.5, fontweight="bold", fontfamily="monospace")
        ax3.text(mid_x, 0.25, label, ha="center", va="center",
                 color=color, fontsize=7.5, multialignment="center")

    ax3.set_title("Example:  VSADD v3, v1, x5  (vector-scalar, rs2 is scalar register)",
                  fontsize=LABEL_FS, loc="left", pad=4)

    fig.tight_layout(rect=[0, 0, 1, 0.94])
    savefig(fig, "slide_s2_encoding.png")


# ═══════════════════════════════════════════════════════════════════════════
# Slide 2 — Instruction categories breakdown
# ═══════════════════════════════════════════════════════════════════════════

def make_categories():
    categories = [
        ("VV_ARITH\nfunct3=000", 11, C_ARITH,
         "VVADD VVSUB VVMUL VVDIV VVREM\nVVAND VVOR VVXOR VVSLL VVSRL VVSRA"),
        ("VS_ARITH\nfunct3=001",  5, C_SCALAR,
         "VSADD  VSSUB  VSMUL  VSDIV  VSREM"),
        ("VMEM\nfunct3=010",      4, C_MEM,
         "VLW   VSW   VLWS  VSWS\n(strided variants)"),
        ("VCONFIG\nfunct3=011",   3, C_CFG,
         "SETVL   CVM   VFENCE"),
        ("VCOMP\nfunct3=100",     6, C_QUEUE,
         "VSEQ VSLT VSLE VSGT VSGE VSNE"),
        ("VREDUCE\nfunct3=101",   3, C_VEC,
         "VREDSUM   VREDAND   VREDOR"),
    ]

    fig, (ax_bar, ax_tbl) = plt.subplots(1, 2, figsize=(14, 5.5),
                                          gridspec_kw={"width_ratios": [1, 1.5]},
                                          facecolor=C_LIGHT)
    fig.suptitle("33 Vector Instructions Across 6 Categories",
                 fontsize=TITLE_FS, fontweight="bold")

    labels = [c[0] for c in categories]
    counts = [c[1] for c in categories]
    colors = [c[2] for c in categories]

    # Horizontal bar chart
    ax_bar.set_facecolor(C_LIGHT)
    y = np.arange(len(categories))
    bars = ax_bar.barh(y, counts, color=colors, alpha=0.85, height=0.6)
    ax_bar.set_yticks(y)
    ax_bar.set_yticklabels(labels, fontsize=9, fontfamily="monospace")
    ax_bar.set_xlabel("Number of instructions", fontsize=LABEL_FS)
    ax_bar.set_title("Instruction count per category", fontsize=LABEL_FS)
    ax_bar.grid(axis="x", alpha=0.3)
    ax_bar.spines["top"].set_visible(False)
    ax_bar.spines["right"].set_visible(False)
    for bar, cnt in zip(bars, counts):
        ax_bar.text(bar.get_width() + 0.1, bar.get_y() + bar.get_height()/2,
                    str(cnt), va="center", fontsize=10, fontweight="bold")
    ax_bar.set_xlim(0, 14)

    # Total annotation
    ax_bar.text(13.5, -0.8, f"Total: {sum(counts)}",
                ha="right", va="center", fontsize=11, fontweight="bold", color=C_DARK)

    # Detail table on the right
    ax_tbl.set_facecolor(C_LIGHT)
    ax_tbl.axis("off")
    ax_tbl.set_xlim(0, 1)
    ax_tbl.set_ylim(0, len(categories) + 0.5)

    for i, (cat, cnt, color, insts) in enumerate(reversed(categories)):
        row_y = i + 0.1
        # Color swatch
        ax_tbl.add_patch(FancyBboxPatch((0, row_y + 0.05), 0.22, 0.78,
                                         boxstyle="round,pad=0.01",
                                         facecolor=color, alpha=0.85, linewidth=0))
        cat_short = cat.split("\n")[0]
        ax_tbl.text(0.11, row_y + 0.44, cat_short,
                    ha="center", va="center", color="white",
                    fontsize=8.5, fontweight="bold", fontfamily="monospace")
        ax_tbl.text(0.24, row_y + 0.44, insts,
                    ha="left", va="center", color=C_DARK,
                    fontsize=7.8, fontfamily="monospace")

    ax_tbl.set_title("Instructions in each category", fontsize=LABEL_FS)

    fig.tight_layout(rect=[0, 0, 1, 0.93])
    savefig(fig, "slide_s2_categories.png")


# ═══════════════════════════════════════════════════════════════════════════
# Slide 3 — Architecture block diagram
# ═══════════════════════════════════════════════════════════════════════════

def _box(ax, x, y, w, h, color, text, text_color="white",
         fs=9, alpha=0.88, radius=0.15, zorder=2):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                                boxstyle=f"round,pad={radius}",
                                facecolor=color, alpha=alpha,
                                edgecolor="white", linewidth=1.2,
                                zorder=zorder))
    ax.text(x + w/2, y + h/2, text, ha="center", va="center",
            color=text_color, fontsize=fs, fontweight="bold",
            multialignment="center", zorder=zorder + 1)


def _arrow(ax, x1, y1, x2, y2, label="", color="white", lw=1.8,
           arrowstyle="-|>", zorder=3):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle=arrowstyle, color=color,
                                lw=lw, connectionstyle="arc3,rad=0"),
                zorder=zorder)
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        ax.text(mx, my, label, ha="center", va="center",
                fontsize=7.5, color=color,
                bbox=dict(facecolor="#1E2A38", edgecolor="none", pad=1.5),
                zorder=zorder + 1)


def make_block_diagram():
    fig, ax = plt.subplots(figsize=(14, 8), facecolor="#1E2A38")
    ax.set_facecolor("#1E2A38")
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 8)
    ax.axis("off")

    fig.suptitle("Vector Coprocessor Architecture", color=C_WHITE,
                 fontsize=TITLE_FS + 1, fontweight="bold", y=0.97)

    # ── Scalar Core (left) ──────────────────────────────────────────────────
    SCALAR_X, SCALAR_Y, SCALAR_W, SCALAR_H = 0.3, 2.4, 3.8, 5.0

    ax.add_patch(FancyBboxPatch((SCALAR_X, SCALAR_Y), SCALAR_W, SCALAR_H,
                                boxstyle="round,pad=0.15",
                                facecolor="#243447", linewidth=2,
                                edgecolor=C_SCALAR, zorder=1))
    ax.text(SCALAR_X + SCALAR_W/2, SCALAR_Y + SCALAR_H - 0.38,
            "Scalar Core  (riscvbyp)", ha="center", va="center",
            color=C_SCALAR, fontsize=LABEL_FS, fontweight="bold")

    # Pipeline stages
    stages = ["Fetch", "Decode", "Execute", "Memory", "Writeback"]
    stage_colors = [C_SCALAR] * 5
    for i, (stage, sc) in enumerate(zip(stages, stage_colors)):
        sy = SCALAR_Y + 0.55 + i * 0.75
        _box(ax, SCALAR_X + 0.3, sy, SCALAR_W - 0.6, 0.62, sc, stage, fs=9, radius=0.05)

    # Dispatch arrow from Execute stage
    ax.annotate("", xy=(4.5, 5.15), xytext=(SCALAR_X + SCALAR_W, 5.15),
                arrowprops=dict(arrowstyle="-|>", color=C_QUEUE, lw=2.0),
                zorder=4)
    ax.text(4.38, 5.45, "dispatch\n(val/rdy)", ha="center", va="center",
            fontsize=7.5, color=C_QUEUE,
            bbox=dict(facecolor="#1E2A38", edgecolor="none", pad=1))

    # ── Command Queue (center) ───────────────────────────────────────────────
    QX, QY, QW, QH = 4.5, 4.6, 1.6, 1.2
    _box(ax, QX, QY, QW, QH, C_QUEUE,
         "Command\nQueue\n(4-entry FIFO)", fs=8, radius=0.08)

    # Queue → Vector
    ax.annotate("", xy=(7.0, 5.2), xytext=(QX + QW, 5.2),
                arrowprops=dict(arrowstyle="-|>", color=C_QUEUE, lw=2.0),
                zorder=4)

    # Full queue → stall scalar
    ax.annotate("", xy=(SCALAR_X + SCALAR_W * 0.85, SCALAR_Y + SCALAR_H * 0.62 + 0.05),
                xytext=(QX, QY + QH * 0.8),
                arrowprops=dict(arrowstyle="-|>", color="#E74C3C", lw=1.4,
                                connectionstyle="arc3,rad=-0.35"),
                zorder=4)
    ax.text(4.15, 4.25, "queue full\n→ stall", ha="center", va="center",
            fontsize=7, color="#E74C3C",
            bbox=dict(facecolor="#1E2A38", edgecolor="none", pad=1))

    # VFENCE stall arc
    ax.annotate("", xy=(SCALAR_X + SCALAR_W * 0.85, SCALAR_Y + SCALAR_H * 0.38),
                xytext=(7.1, 3.4),
                arrowprops=dict(arrowstyle="-|>", color="#E74C3C", lw=1.4,
                                connectionstyle="arc3,rad=0.4"),
                zorder=4)
    ax.text(5.0, 3.3, "VFENCE\n→ stall until idle", ha="center", va="center",
            fontsize=7, color="#E74C3C",
            bbox=dict(facecolor="#1E2A38", edgecolor="none", pad=1))

    # ── Vector Unit (right) ─────────────────────────────────────────────────
    VX, VY, VW, VH = 7.0, 2.0, 6.5, 5.6
    ax.add_patch(FancyBboxPatch((VX, VY), VW, VH,
                                boxstyle="round,pad=0.15",
                                facecolor="#243447", linewidth=2,
                                edgecolor=C_VEC, zorder=1))
    ax.text(VX + VW/2, VY + VH - 0.38,
            "Vector Unit", ha="center", va="center",
            color=C_VEC, fontsize=LABEL_FS, fontweight="bold")

    # VecCtrl FSM
    _box(ax, VX + 0.3, VY + 3.7, VW - 0.6, 1.1, C_CFG,
         "VecCtrl FSM\nIDLE → EXEC / LOAD / STORE / REDUCE → IDLE",
         fs=8, radius=0.08)

    # VecDpath container
    ax.add_patch(FancyBboxPatch((VX + 0.3, VY + 0.3), VW - 0.6, 3.1,
                                boxstyle="round,pad=0.1",
                                facecolor="#1A2A3A", linewidth=1,
                                edgecolor="#445566", zorder=2))
    ax.text(VX + VW/2, VY + 3.15,
            "VecDpath", ha="center", va="center",
            color="#AABBCC", fontsize=9, fontweight="bold")

    # Sub-components in VecDpath
    sub = [
        ("VecRegfile\n8 regs × 32 elem × 32b = 1KB",   VX + 0.5, VY + 2.25, 2.8, 0.75, C_MEM),
        ("VecALU × 4  (4 SIMD lanes)\nadd/sub/mul/div/rem  and/or/xor/cmp",
                                                        VX + 3.5, VY + 2.25, 2.9, 0.75, C_ARITH),
        ("Mask Register  (32-bit)",                      VX + 0.5, VY + 1.45, 2.5, 0.65, C_QUEUE),
        ("Reduce Acc  (32-bit)",                         VX + 3.2, VY + 1.45, 2.5, 0.65, C_SCALAR),
        ("Element counter  (0 … VL-1)",                  VX + 0.5, VY + 0.5,  5.2, 0.62, "#556677"),
    ]
    for label, sx, sy, sw, sh, sc in sub:
        _box(ax, sx, sy, sw, sh, sc, label, fs=7.5, radius=0.06, alpha=0.80)

    # FSM → Dpath control arrow
    ax.annotate("", xy=(VX + VW/2, VY + 3.4), xytext=(VX + VW/2, VY + 3.05 + 0.3 + 0.8 - 0.1),
                arrowprops=dict(arrowstyle="-|>", color=C_CFG, lw=1.5), zorder=4)

    # Result write-back to scalar
    ax.annotate("", xy=(SCALAR_X + SCALAR_W, SCALAR_Y + 1.35),
                xytext=(VX, SCALAR_Y + 1.35),
                arrowprops=dict(arrowstyle="-|>", color=C_VEC, lw=1.4,
                                connectionstyle="arc3,rad=0.0"),
                zorder=4)
    ax.text(5.5, SCALAR_Y + 1.1, "reduce result / scalar\nwrite-back (VREDSUM)",
            ha="center", va="center", fontsize=7, color=C_VEC,
            bbox=dict(facecolor="#1E2A38", edgecolor="none", pad=1))

    # Vec idle signal
    ax.annotate("", xy=(SCALAR_X + SCALAR_W, SCALAR_Y + 0.8),
                xytext=(QX, SCALAR_Y + 0.8),
                arrowprops=dict(arrowstyle="-|>", color=C_CFG, lw=1.2,
                                linestyle="dashed",
                                connectionstyle="arc3,rad=0.0"),
                zorder=4)
    ax.text(4.3, SCALAR_Y + 0.5, "vec_idle signal", ha="center", va="center",
            fontsize=7, color=C_CFG,
            bbox=dict(facecolor="#1E2A38", edgecolor="none", pad=1))

    # ── Data Memory (bottom) ────────────────────────────────────────────────
    _box(ax, 0.3, 0.2, 13.4, 1.0, "#2E5077",
         "Data Memory  (shared, arbitrated via  !vec_idle  signal)",
         fs=10, radius=0.12, alpha=0.90)

    # Scalar → memory
    ax.annotate("", xy=(1.8, 1.2), xytext=(1.8, SCALAR_Y),
                arrowprops=dict(arrowstyle="<->", color=C_SCALAR, lw=1.6), zorder=4)
    ax.text(2.2, 1.8, "dmem\nreq/resp", ha="left", va="center",
            fontsize=7.5, color=C_SCALAR)

    # Vector → memory
    ax.annotate("", xy=(10.0, 1.2), xytext=(10.0, VY),
                arrowprops=dict(arrowstyle="<->", color=C_MEM, lw=1.6), zorder=4)
    ax.text(10.3, 1.8, "vmem\nreq/resp", ha="left", va="center",
            fontsize=7.5, color=C_MEM)

    # Instruction memory (top)
    _box(ax, 0.3, 7.2, 3.8, 0.65, "#2E5077",
         "Instruction Memory  (separate port)", fs=9, radius=0.08)
    ax.annotate("", xy=(1.8, 7.2), xytext=(1.8, SCALAR_Y + SCALAR_H),
                arrowprops=dict(arrowstyle="<->", color=C_GRAY, lw=1.4), zorder=4)

    fig.tight_layout(rect=[0, 0, 1, 0.96])
    savefig(fig, "slide_s3_block_diagram.png")


# ═══════════════════════════════════════════════════════════════════════════
# Slide 3 — VecCtrl FSM state diagram
# ═══════════════════════════════════════════════════════════════════════════

def make_fsm():
    fig, ax = plt.subplots(figsize=(12, 8), facecolor="#1E2A38")
    ax.set_facecolor("#1E2A38")
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 8)
    ax.axis("off")

    fig.suptitle("VecCtrl FSM  —  Vector Unit Control State Machine",
                 color=C_WHITE, fontsize=TITLE_FS + 1, fontweight="bold")

    states = {
        "IDLE":    (6.0, 6.5),
        "EXEC":    (10.0, 4.5),
        "LOAD":    (8.5, 2.0),
        "LWAIT":   (5.5, 0.8),
        "STORE":   (3.0, 2.0),
        "REDUCE":  (2.0, 4.5),
    }
    state_colors = {
        "IDLE":   C_CFG,
        "EXEC":   C_ARITH,
        "LOAD":   C_MEM,
        "LWAIT":  "#2ECC71",
        "STORE":  C_SCALAR,
        "REDUCE": C_VEC,
    }
    state_desc = {
        "IDLE":   "waiting for cmd",
        "EXEC":   "iterate VL elems\nALU write-back",
        "LOAD":   "issue mem read\nfor elem[i]",
        "LWAIT":  "wait mem resp\nwrite to vreg",
        "STORE":  "issue mem write\nfor elem[i]",
        "REDUCE": "accumulate\nelem[i]",
    }
    R = 0.72  # circle radius

    # Draw state circles
    for name, (cx, cy) in states.items():
        color = state_colors[name]
        circle = plt.Circle((cx, cy), R, color=color, alpha=0.88, zorder=3)
        ax.add_patch(circle)
        ax.text(cx, cy + 0.12, name, ha="center", va="center",
                color="white", fontsize=10, fontweight="bold", zorder=4)
        ax.text(cx, cy - 0.28, state_desc[name], ha="center", va="center",
                color="white", fontsize=6.8, multialignment="center", zorder=4)

    # Helper: draw curved arrow between states
    def arc_arrow(src, dst, label, rad=0.3, label_offset=(0, 0), color="#AACCEE"):
        sx, sy = states[src]
        dx, dy = states[dst]
        # Shorten to circle edge
        import math
        angle = math.atan2(dy - sy, dx - sx)
        ax.annotate("", xy=(dx - R * math.cos(angle), dy - R * math.sin(angle)),
                    xytext=(sx + R * math.cos(angle), sy + R * math.sin(angle)),
                    arrowprops=dict(arrowstyle="-|>", color=color, lw=1.6,
                                    connectionstyle=f"arc3,rad={rad}"),
                    zorder=5)
        # Label at midpoint with offset
        mx = (sx + dx) / 2 + label_offset[0]
        my = (sy + dy) / 2 + label_offset[1]
        ax.text(mx, my, label, ha="center", va="center",
                fontsize=7.5, color=color,
                bbox=dict(facecolor="#1E2A38", edgecolor=color, linewidth=0.5,
                          boxstyle="round,pad=1.5"),
                zorder=6)

    # ── Transitions ──────────────────────────────────────────────────────────

    # IDLE → EXEC: VV/VS arith
    arc_arrow("IDLE", "EXEC", "VV/VS arith\n(CAT_VV or CAT_VS)", rad=-0.2,
              label_offset=(0.5, 0.6), color=C_ARITH)

    # IDLE → LOAD: VLW / VLWS
    arc_arrow("IDLE", "LOAD", "VLW / VLWS", rad=-0.15,
              label_offset=(1.0, -0.2), color=C_MEM)

    # IDLE → STORE: VSW / VSWS
    arc_arrow("IDLE", "STORE", "VSW / VSWS", rad=0.15,
              label_offset=(-1.0, -0.2), color=C_SCALAR)

    # IDLE → REDUCE: VREDSUM/AND/OR
    arc_arrow("IDLE", "REDUCE", "VREDSUM/AND/OR\n(CAT_VV, reduce)", rad=0.2,
              label_offset=(-0.5, 0.6), color=C_VEC)

    # EXEC → IDLE
    arc_arrow("EXEC", "IDLE", "elem+1 ≥ VL", rad=-0.3,
              label_offset=(0.8, -0.5), color=C_ARITH)

    # LOAD → LWAIT
    arc_arrow("LOAD", "LWAIT", "memreq_rdy", rad=-0.2,
              label_offset=(0.6, -0.2), color=C_MEM)

    # LWAIT → LOAD (more elements)
    arc_arrow("LWAIT", "LOAD", "memresp_val\n& more elem", rad=-0.2,
              label_offset=(-0.6, 0.1), color="#2ECC71")

    # LWAIT → IDLE (last element)
    arc_arrow("LWAIT", "IDLE", "memresp_val\n& last elem", rad=0.35,
              label_offset=(-1.8, 1.2), color="#2ECC71")

    # STORE → STORE (self, more elements) — small loop
    sx, sy = states["STORE"]
    loop = plt.Circle((sx - 0.7, sy + 0.9), 0.45,
                       fill=False, edgecolor=C_SCALAR, linewidth=1.5, zorder=5)
    ax.add_patch(loop)
    ax.text(sx - 1.35, sy + 0.9, "memreq_rdy\n& more elem",
            ha="center", va="center", fontsize=7, color=C_SCALAR)

    # STORE → IDLE
    arc_arrow("STORE", "IDLE", "memreq_rdy\n& last elem", rad=0.25,
              label_offset=(-0.5, 0.8), color=C_SCALAR)

    # REDUCE → IDLE
    arc_arrow("REDUCE", "IDLE", "last elem\n→ write scalar", rad=0.3,
              label_offset=(-1.0, 0.8), color=C_VEC)

    # IDLE self-loop for CFG (SETVL, CVM)
    sx, sy = states["IDLE"]
    loop_cfg = plt.Circle((sx + 1.1, sy + 0.6), 0.42,
                           fill=False, edgecolor=C_CFG, linewidth=1.5, zorder=5)
    ax.add_patch(loop_cfg)
    ax.text(sx + 1.9, sy + 0.6, "CAT_CFG\n(SETVL, CVM)", ha="center", va="center",
            fontsize=7, color=C_CFG)

    # Legend
    legend_items = [
        (C_CFG,   "IDLE — awaits commands"),
        (C_ARITH, "EXEC — element arithmetic"),
        (C_MEM,   "LOAD/LWAIT — vector load"),
        (C_SCALAR,"STORE — vector store"),
        (C_VEC,   "REDUCE — tree reduction"),
    ]
    for i, (color, label) in enumerate(legend_items):
        dot = plt.Circle((0.45, 7.4 - i * 0.52), 0.18, color=color, alpha=0.85, zorder=5)
        ax.add_patch(dot)
        ax.text(0.75, 7.4 - i * 0.52, label, va="center", color="white",
                fontsize=8, zorder=5)

    fig.tight_layout(rect=[0, 0, 1, 0.95])
    savefig(fig, "slide_s3_fsm.png")


# ═══════════════════════════════════════════════════════════════════════════
# Slide 3 — Chaining diagram
# ═══════════════════════════════════════════════════════════════════════════

def make_chaining():
    """
    Two-row timeline showing VSMUL → VVADD with and without chaining.
    Uses VL=8 so the diagram is readable at slide size.
    """
    VL = 8
    OVERHEAD = 4   # cycles of scalar setup before first vec instruction

    fig, axes = plt.subplots(2, 1, figsize=(13, 6), facecolor=C_DARK)
    fig.suptitle("Cray-Style Vector Chaining  —  VSMUL → VVADD  (VL = 8)",
                 color=C_WHITE, fontsize=TITLE_FS + 1, fontweight="bold", y=0.97)

    configs = [
        ("Without chaining  (riscvvec)",        False),
        ("With chaining     (riscvvec-chained)", True),
    ]

    for ax, (label, chain) in zip(axes, configs):
        ax.set_facecolor("#1A2332")
        total = OVERHEAD + VL + (1 if chain else VL) + VL
        ax.set_xlim(-1, total + 2)
        ax.set_ylim(-0.3, 3.2)
        ax.axis("off")

        ax.text(-0.5, 2.8, label, color=C_WHITE, fontsize=LABEL_FS,
                fontweight="bold", va="top")

        ROW_MUL  = 1.8
        ROW_ADD  = 0.7
        H        = 0.75

        # Scalar setup block
        ax.add_patch(FancyBboxPatch((0, ROW_MUL - H/2), OVERHEAD, H * 2.1,
                                    boxstyle="round,pad=0.1",
                                    facecolor=C_SCALAR, alpha=0.5, linewidth=0))
        ax.text(OVERHEAD/2, ROW_MUL + 0.5, "scalar\nsetup", ha="center", va="center",
                color=C_WHITE, fontsize=8)

        # VSMUL elements
        mul_start = OVERHEAD
        for i in range(VL):
            shade = 0.55 + 0.045 * i
            ax.add_patch(FancyBboxPatch((mul_start + i, ROW_MUL - H/2), 0.92, H,
                                        boxstyle="round,pad=0.04",
                                        facecolor=C_ARITH, alpha=shade, linewidth=0))
            ax.text(mul_start + i + 0.46, ROW_MUL, f"e{i}",
                    ha="center", va="center", color=C_WHITE, fontsize=7.5,
                    fontweight="bold")

        ax.text(mul_start + VL/2, ROW_MUL + H/2 + 0.08, "VSMUL",
                ha="center", va="bottom", color=C_ARITH, fontsize=9, fontweight="bold")

        # VVADD start: chained = mul_start+1, unchained = mul_start+VL
        add_start = mul_start + 1 if chain else mul_start + VL

        for i in range(VL):
            shade = 0.55 + 0.045 * i
            ax.add_patch(FancyBboxPatch((add_start + i, ROW_ADD - H/2), 0.92, H,
                                        boxstyle="round,pad=0.04",
                                        facecolor=C_MEM, alpha=shade, linewidth=0))
            ax.text(add_start + i + 0.46, ROW_ADD, f"e{i}",
                    ha="center", va="center", color=C_WHITE, fontsize=7.5,
                    fontweight="bold")

        ax.text(add_start + VL/2, ROW_ADD - H/2 - 0.08, "VVADD",
                ha="center", va="top", color=C_MEM, fontsize=9, fontweight="bold")

        # Row labels
        ax.text(-0.7, ROW_MUL, "VSMUL", ha="right", va="center",
                color=C_ARITH, fontsize=9, fontweight="bold")
        ax.text(-0.7, ROW_ADD, "VVADD", ha="right", va="center",
                color=C_MEM,   fontsize=9, fontweight="bold")

        # Total cycles brace
        total_exec = add_start + VL
        ax.annotate("", xy=(total_exec, -0.15), xytext=(mul_start, -0.15),
                    arrowprops=dict(arrowstyle="<->", color=C_WHITE, lw=1.5))
        saving = (VL - 1) if chain else 0
        base   = VL * 2
        cyc_label = (f"{total_exec - mul_start} cycles  "
                     f"(saves {saving} vs unchained)" if chain
                     else f"{total_exec - mul_start} cycles")
        ax.text((total_exec + mul_start)/2, -0.25, cyc_label,
                ha="center", va="top", color=C_WHITE, fontsize=9, fontweight="bold")

        # Forwarding arrow for chained case
        if chain:
            for i in range(min(3, VL)):
                ax.annotate("", xy=(add_start + i + 0.46, ROW_ADD + H/2),
                            xytext=(mul_start + i + 0.46, ROW_MUL - H/2),
                            arrowprops=dict(arrowstyle="-|>", color="#FFDD88",
                                            lw=0.9, alpha=0.7))
            ax.text(mul_start + 1.5, (ROW_MUL + ROW_ADD)/2,
                    "forwarded\neach cycle", ha="left", va="center",
                    color="#FFDD88", fontsize=7.5, style="italic")

        # X axis ticks
        ax.set_xticks([])
        for t in range(int(ax.get_xlim()[1]) + 1):
            ax.text(t + 0.5, -0.05, str(t), ha="center", va="top",
                    color=C_GRAY, fontsize=6.5)
        ax.text(total_exec / 2, 3.1, "cycle →", ha="center", va="top",
                color=C_GRAY, fontsize=7.5, style="italic")

    fig.tight_layout(rect=[0, 0, 1, 0.94])
    savefig(fig, "slide_s3_chaining.png")


# ═══════════════════════════════════════════════════════════════════════════
# Slide 4 — Testing methodology visual
# ═══════════════════════════════════════════════════════════════════════════

def make_testing_overview():
    """
    Visual grid showing test coverage: categories × test types.
    """
    fig, ax = plt.subplots(figsize=(13, 6), facecolor=C_LIGHT)
    ax.set_facecolor(C_LIGHT)
    ax.axis("off")
    fig.suptitle("Test Coverage  —  44 / 44 Pass", fontsize=TITLE_FS + 1,
                 fontweight="bold")

    categories = [
        ("Scalar ISA\n(43 tests)",  C_SCALAR,
         ["add/addi", "sub", "and/or/xor", "sll/srl/sra",
          "slt/sltu", "lui", "lw/sw", "lb/lh/sb/sh",
          "beq/bne/blt", "bge/bgeu/bltu", "jal/jalr/jr",
          "mul/div/rem", "…all RV32IM"]),
        ("VV Arithmetic\n(riscv-vec.S)", C_ARITH,
         ["VVADD", "VVSUB", "VVMUL", "VVAND", "VVOR", "VVXOR"]),
        ("VS Arithmetic\n(riscv-vec.S)", C_VEC,
         ["VSADD", "VSMUL", "VSSUB"]),
        ("Memory\n(riscv-vec.S)", C_MEM,
         ["VLW round-trip", "VSW round-trip", "VFENCE sync"]),
        ("Config & Edge\n(riscv-vec.S)", C_CFG,
         ["SETVL normal", "SETVL VL=1", "SETVL VL=0",
          "Negative nums", "Decoupled queue"]),
        ("C Ubmarks\n(regression)", "#556677",
         ["ubmark-vvadd", "ubmark-bin-search",
          "ubmark-cmplx-mult", "ubmark-masked-filter"]),
    ]

    COL_W = 13.0 / len(categories)
    for col, (title, color, tests) in enumerate(categories):
        x0 = col * COL_W + 0.1
        # Header
        ax.add_patch(FancyBboxPatch((x0, 4.5), COL_W - 0.2, 0.9,
                                    boxstyle="round,pad=0.08",
                                    facecolor=color, alpha=0.9, linewidth=0))
        ax.text(x0 + (COL_W - 0.2)/2, 4.95, title,
                ha="center", va="center", color=C_WHITE,
                fontsize=8, fontweight="bold", multialignment="center")
        # Test rows
        for row, t in enumerate(tests):
            y = 4.1 - row * 0.58
            ax.add_patch(FancyBboxPatch((x0, y - 0.22), COL_W - 0.2, 0.42,
                                        boxstyle="round,pad=0.04",
                                        facecolor=color, alpha=0.18, linewidth=0))
            ax.add_patch(FancyBboxPatch((x0 + 0.04, y - 0.16), 0.22, 0.3,
                                        boxstyle="round,pad=0.02",
                                        facecolor="#5BAD72", alpha=0.9, linewidth=0))
            ax.text(x0 + 0.15, y, "✓", ha="center", va="center",
                    color=C_WHITE, fontsize=7, fontweight="bold")
            ax.text(x0 + 0.32, y, t, ha="left", va="center",
                    color=C_DARK, fontsize=7.5)

    # Summary row at bottom
    ax.add_patch(FancyBboxPatch((0.1, -0.35), 12.8, 0.55,
                                boxstyle="round,pad=0.08",
                                facecolor=C_DARK, alpha=0.85, linewidth=0))
    ax.text(6.5, -0.08,
            "44 / 44 pass   ·   43 scalar ISA tests   ·   13 vector sub-tests   ·   4 C regression benchmarks",
            ha="center", va="center", color=C_WHITE, fontsize=10, fontweight="bold")

    ax.set_xlim(0, 13)
    ax.set_ylim(-0.5, 5.7)
    fig.tight_layout(rect=[0, 0, 1, 0.94])
    savefig(fig, "slide_s4_testing.png")


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("\nGenerating slide graphics …\n")
    make_code_compare()
    make_timeline()
    make_encoding()
    make_categories()
    make_block_diagram()
    make_fsm()
    make_chaining()
    make_testing_overview()
    print(f"\nAll figures saved to  {OUT}/\n")
